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
/// `NoteTree.Node.Kind` is not extended for boards (D10): every leaf in this tree is a
/// board, so the icon is this view's business and the enum stays as it is.
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
    @State private var tree: [NoteTree.Node] = []
    @State private var boards: [String] = []
    @State private var isCreatingWorkspace = false
    @State private var isRenamingWorkspace = false
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
        .sheet(isPresented: $isRenamingWorkspace) {
            RenameWorkspaceSheet(
                folder: targetFolder,
                isNameAvailable: nameIsAvailable,
                onConfirm: { newName in
                    isRenamingWorkspace = false
                    actions.rename(targetFolder, newName)
                },
                onCancel: { isRenamingWorkspace = false }
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
            onRename: { isRenamingWorkspace = true },
            onDelete: { confirmDelete(of: targetFolder) },
            // The same `expanded` binding the tree's context menu drives: two places to
            // reach one piece of state, never two pieces of state (ADR-0022 §D8).
            onExpandAll: { expanded = Self.allFolders(in: tree) },
            onCollapseAll: { expanded = [] }
        )
    }

    /// The folder the toolbar's verbs act on: the selected row, with no fallback
    /// (ADR-0024 §D7 withdraws ADR-0022 §D9's fallback onto the open board's folder -
    /// with nothing selected, Rinomina/Elimina are now disabled rather than aiming at a
    /// row the user cannot see).
    ///
    /// ADR-0024 Task 4 (coder): replace with `Self.target(for:)` reading a
    /// `WorkspaceSelection` directly, "one expression, no branch on which case it is"
    /// (R-06) - this is the minimal form Task 3's removal of the fallback leaves
    /// compiling, not that expression.
    private var targetFolder: String { selectedFolder ?? "" }

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

    /// The folder rules, over the open vault's root. Nil with no vault open, which is
    /// also when the toolbar has nothing to act on.
    private var folderOperations: FolderFileOperations? {
        vault.root.map { FolderFileOperations(store: NoteStore(root: $0)) }
    }

    // MARK: Verbs
    //
    // The browser decides, `WorkspaceView` performs (ADR-0022 §D10): create and rename
    // hand the sheet's answer straight to `actions`, which is where `flushPendingSave()`
    // and `open(folder:)` bracket the vault call. Delete is the one that stops here
    // first, because what it needs before it can ask - how much is inside - is a walk of
    // the folder rather than a decision.

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
    // ADR-0024 Task 3 GREEN (coder): rebuild as List(selection:) with WorkspaceRow flat
    // recursive rows. The tester's batch (this one) only removes what compilation
    // forces it to - `selectedFolder`'s promotion from `@State` to a handed-down value,
    // `onOpen`/`onDeselect` folding into `onSelect` - and cannot build the derived
    // `Binding<String?>` (getter `selectedFolder`, setter resolving through
    // `WorkspaceTree.node(withID:in:)` into `onSelect`), the two `List(selection:)`
    // trees, the `WorkspaceTreeRow` → `WorkspaceRow` flat-recursive rewrite, `.tag`,
    // the accessibility labels, or the context-menu relocation - all real view code
    // with no unit-level red, whose red lives in Task 6's UI suite (plan, Task 3).
    // `WorkspaceTreeRow` below is left exactly as it was and is unused by these stubs;
    // do not delete it, the coder's rewrite reads it as the shape to replace.

    private var folderTree: some View {
        EmptyView()
    }

    /// Every board in one list while a filter is typed: a match three folders down is
    /// easier to see flat than as a tree opened around it - the note sidebar's rule,
    /// and the reason the filter field behaves the same in both places.
    private var flatList: some View {
        EmptyView()
    }

    private var filteredBoards: [String] {
        boards.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    // MARK: Tree state

    private func rebuild() {
        boards = vault.root.map { CanvasStore(root: $0).allBoards() } ?? []
        tree = NoteTree.build(fromPaths: boards)
        // A selection is a path, and a rename or a delete has just moved or removed the
        // folder it names - this runs on `scanGeneration`, which both of them bump.
        // `selectedFolder` is owned by the controller now (ADR-0024 §D6), so dropping a
        // stale one means asking for `nil` through `onSelect` rather than assigning
        // local state - there no longer is any to assign.
        //
        // ADR-0024 Task 4 (coder): retarget the stale-selection check itself against
        // `WorkspaceTree.folders(in:)`, which is the set that actually includes the
        // root (`""`); `Self.allFolders(in:)` below is `NoteTree`-based and does not
        // (ADR-0024 §D7, plan Task 4).
        if let selectedFolder, !Self.allFolders(in: tree).contains(selectedFolder) {
            onSelect(nil)
        }
        reveal(selectedFolder)
    }

    /// Opens the folders above a board, so one opened from somewhere that is not this
    /// list is visible in it rather than merely selected inside a closed folder.
    private func reveal(_ path: String?) {
        guard let path else { return }
        expanded.formUnion(NoteTree.ancestors(of: path))
    }

    // Widened from `private` to the file's default (internal) access, additive and
    // signature-preserving, so `Tests/WorkspaceBrowserToolbarTests.swift` can reach it
    // through `@testable import Pergamenum` (ADR-0022, plan Task 5, R-01). No behaviour
    // changed - same body, same call sites, only visibility.
    static func allFolders(in nodes: [NoteTree.Node]) -> Set<String> {
        var result: Set<String> = []
        for node in nodes where node.kind == .folder {
            result.insert(node.id)
            result.formUnion(allFolders(in: node.children ?? []))
        }
        return result
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
    /// STUB (ADR-0024 Task 3, tester's batch): returns `[]` unconditionally, never
    /// `fatalError()` or a force-unwrap, so `Tests/WorkspaceTreeTests.swift`'s two new
    /// assertions are red on their expectations rather than on a build error. The
    /// coder's GREEN implements the real fold, `static` and internal, the same
    /// visibility `allFolders(in:)` above already has.
    static func rows(matching filter: String, in tree: [WorkspaceTree.Node]) -> [WorkspaceTree.Node] {
        []
    }

    /// The three identifier spellings a row can carry, and the only place they are
    /// spelled (ADR-0024 §D10): `workspace-board-<boardPath>` for a `.workspace` that
    /// owns a board, `workspace-folder-<id>` for one that does not,
    /// `workspace-foreign-board-<path>` for a `.foreignBoard`.
    ///
    /// STUB (ADR-0024 Task 3, tester's batch): returns `""` unconditionally, never
    /// `fatalError()` or a force-unwrap, so `Tests/WorkspaceTreeTests.swift`'s new
    /// assertions are red on their expectations rather than on a build error. The
    /// coder's GREEN implements the real spelling.
    static func identifier(for node: WorkspaceTree.Node) -> String {
        ""
    }
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
/// A `DisclosureGroup` bound to the shared `expanded` set rather than one owning its
/// own state: "Espandi tutto" and a board revealed from outside both have to be able to
/// open a folder this row did not open itself.
private struct WorkspaceTreeRow: View {
    @Environment(\.theme) private var theme

    let node: NoteTree.Node
    @Binding var expanded: Set<String>
    /// The folder the toolbar acts on. A row writes to it; nothing here reads it except
    /// to draw itself as the selected one (ADR-0022 §D9).
    @Binding var selected: String?
    let openBoardPath: String?
    let onOpen: (String) -> Void
    /// The two folder verbs, by folder path. The row does not perform them: it hands the
    /// path to the same closures the toolbar's buttons call, so the context menu is a
    /// second entry point rather than a second code path (ADR-0023 §D4).
    let onRename: (String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        switch node.kind {
        case .folder: folderRow
        case .note: boardRow
        }
    }

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expanded.contains(node.id) },
            set: { isOpen in
                if isOpen {
                    expanded.insert(node.id)
                } else {
                    expanded.remove(node.id)
                }
            }
        )
    }

    private var folderRow: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            ForEach(node.children ?? []) { child in
                WorkspaceTreeRow(
                    node: child,
                    expanded: $expanded,
                    selected: $selected,
                    openBoardPath: openBoardPath,
                    onOpen: onOpen,
                    onRename: onRename,
                    onDelete: onDelete
                )
            }
        } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: isExpanded.wrappedValue ? "folder" : "folder.fill")
                    .foregroundStyle(theme.color(.accentPrimary))
                Text(node.name)
                    .themedText(.body, color: selected == node.id ? .accentPrimary : .textPrimary)
                    .lineLimit(1)
                Spacer(minLength: theme.spacing(.xs))
                Text("\(node.noteCount)").themedText(.caption, color: .textTertiary)
            }
            .contentShape(Rectangle())
            // Selects the folder without toggling its disclosure (ADR-0022 §D9): the
            // triangle opens it, the label says which folder the toolbar's verbs mean.
            .onTapGesture { selected = node.id }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Cartella \(node.name), \(node.noteCount) Workspace")
            // On macOS an `.accessibilityIdentifier` on the `DisclosureGroup` itself
            // propagates onto every descendant AX element - including the disclosed
            // ForEach rows below, overriding each one's own identifier (confirmed the
            // same way the TasksView.swift `task-project-group` fix was: an exported
            // UI-hierarchy attachment). `label:` and the disclosed content are siblings
            // under the `DisclosureGroup`, never one containing the other, so putting the
            // identifier here - on this label's own combined element, which has no
            // pre-existing identifier of its own to clobber - never touches them.
            .accessibilityIdentifier("workspace-folder-\(node.id)")
            // On this label and never on the `DisclosureGroup` above it, for the reason
            // the note beside the identifier gives: a modifier there reaches every
            // disclosed descendant, so the parent folder's «Elimina» would hang off every
            // board row nested inside it - right-clicking a board would offer to delete
            // the folder it lives in (ADR-0023 §D2).
            //
            // Plain titles, no SF Symbols: the toolbar keeps its `pencil`/`trash` and this
            // menu keeps the absence of one, which is what «the same symbol» means for a
            // surface that draws none (ADR-0023 §D1).
            .contextMenu {
                // The same rule the toolbar's two buttons are enabled by, asked in the
                // second place it is rendered rather than restated (ADR-0023 §D1, §D3).
                if WorkspaceBrowserToolbar.canMutate(folder: node.id) {
                    // The selection first: both sheets are seeded from
                    // `WorkspaceBrowser.targetFolder`, which reads it, and a secondary
                    // click fires no `onTapGesture` - so without this the verb would act
                    // on whatever was clicked before the right-click (ADR-0023 §D4).
                    Button("Rinomina…") {
                        selected = node.id
                        onRename(node.id)
                    }
                    Button("Elimina…", role: .destructive) {
                        selected = node.id
                        onDelete(node.id)
                    }
                }
            }
        }
    }

    private var boardRow: some View {
        let isOpen = node.id == openBoardPath
        return Button {
            // A board is named after its folder, so "the selected workspace" is that
            // folder - clicking a board selects it and opens the board, as it always did
            // (ADR-0022 §D9).
            selected = (node.id as NSString).deletingLastPathComponent
            onOpen(node.id)
        } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "rectangle.3.group")
                    .foregroundStyle(theme.color(isOpen ? .accentPrimary : .textTertiary))
                Text(node.name)
                    .themedText(.body, color: isOpen ? .accentPrimary : .textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Workspace \(node.name)")
        .accessibilityIdentifier("workspace-board-\(node.id)")
    }
}
