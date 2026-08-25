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

    /// The board the Workspace is currently showing, drawn as the selected row.
    var openBoardPath: String?
    /// Vault-relative path of the board the user picked.
    var onOpen: (String) -> Void

    @State private var filter = ""
    /// The folders currently open, by path. View state rather than a preference, for
    /// the same reason the note tree's is.
    @State private var expanded: Set<String> = []
    @State private var tree: [NoteTree.Node] = []
    @State private var boards: [String] = []
    /// The row the toolbar's verbs act on, as a folder path (ADR-0022 §D9). Nil until
    /// something is clicked, which is not the same as the vault root: `targetFolder`
    /// falls back to the open board's folder so the toolbar is never inert for lack of a
    /// click.
    @State private var selectedFolder: String?
    @State private var isCreatingWorkspace = false
    @State private var isRenamingWorkspace = false

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
        .onChange(of: openBoardPath) { _, path in reveal(path) }
        .sheet(isPresented: $isCreatingWorkspace) {
            NewWorkspaceSheet(
                parents: WorkspaceFolderSheets.parentOptions(from: boards),
                initialParent: targetFolder,
                isNameAvailable: nameIsAvailable,
                onConfirm: { name, parent in
                    isCreatingWorkspace = false
                    createWorkspace(named: name, in: parent)
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
                    renameWorkspace(targetFolder, to: newName)
                },
                onCancel: { isRenamingWorkspace = false }
            )
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        WorkspaceBrowserToolbar(
            target: targetFolder,
            onNew: { isCreatingWorkspace = true },
            onRename: { isRenamingWorkspace = true },
            onDelete: { deleteWorkspace(targetFolder) },
            // The same `expanded` binding the tree's context menu drives: two places to
            // reach one piece of state, never two pieces of state (ADR-0022 §D8).
            onExpandAll: { expanded = Self.allFolders(in: tree) },
            onCollapseAll: { expanded = [] }
        )
    }

    /// The folder the toolbar's verbs act on: the selected row, or the open board's own
    /// folder when nothing has been clicked (ADR-0022 §D9).
    private var targetFolder: String {
        if let selectedFolder { return selectedFolder }
        guard let openBoardPath else { return "" }
        return (openBoardPath as NSString).deletingLastPathComponent
    }

    /// The collision predicate both sheets block on, live, so a name that is already
    /// taken is refused before anything is created rather than reported afterwards
    /// (ADR-0022 §D11, R-03).
    ///
    /// The same function the performing code guards with
    /// (`FolderFileOperations.nameIsAvailable`), reached through the vault's root - not a
    /// second spelling of the rule for the sheet to disagree with.
    private func nameIsAvailable(_ name: String, in parent: String) -> Bool {
        guard let root = vault.root else { return true }
        return FolderFileOperations(store: NoteStore(root: root)).nameIsAvailable(name, in: parent)
    }

    // MARK: Verbs
    //
    // Inert for now, and it is one decision rather than three: all three verbs need the
    // `WorkspaceController` that `WorkspaceView` owns - `flushPendingSave()` before
    // anything touches disk, or the autosave lands on the old path afterwards, and
    // `open(folder:)` after a rename or a delete so the board follows (ADR-0022 §D10).
    // This view has no business holding that controller, so `WorkspaceView` passes the
    // actions in. Until it does, a confirmed sheet closes and writes nothing: a rename
    // performed here would be one the open board could not follow.

    private func createWorkspace(named name: String, in parent: String) {}

    private func renameWorkspace(_ folder: String, to newName: String) {}

    private func deleteWorkspace(_ folder: String) {}

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

    private var folderTree: some View {
        List {
            ForEach(tree) { node in
                WorkspaceTreeRow(
                    node: node,
                    expanded: $expanded,
                    selected: $selectedFolder,
                    openBoardPath: openBoardPath,
                    onOpen: onOpen
                )
            }
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("workspace-tree")
        .contextMenu {
            Button("Espandi tutto") { expanded = Self.allFolders(in: tree) }
            Button("Comprimi tutto") { expanded = [] }
        }
    }

    /// Every board in one list while a filter is typed: a match three folders down is
    /// easier to see flat than as a tree opened around it - the note sidebar's rule,
    /// and the reason the filter field behaves the same in both places.
    private var flatList: some View {
        List {
            ForEach(filteredBoards, id: \.self) { path in
                WorkspaceTreeRow(
                    node: NoteTree.Node(
                        id: path,
                        name: ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
                        kind: .note,
                        children: nil,
                        noteCount: 1
                    ),
                    expanded: $expanded,
                    selected: $selectedFolder,
                    openBoardPath: openBoardPath,
                    onOpen: onOpen
                )
            }
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("workspace-flat-list")
    }

    private var filteredBoards: [String] {
        boards.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    // MARK: Tree state

    private func rebuild() {
        boards = vault.root.map { CanvasStore(root: $0).allBoards() } ?? []
        tree = NoteTree.build(fromPaths: boards)
        reveal(openBoardPath)
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
                    onOpen: onOpen
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
