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

    var body: some View {
        VStack(spacing: 0) {
            header
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

    private var folderTree: some View {
        List {
            ForEach(tree) { node in
                WorkspaceTreeRow(
                    node: node,
                    expanded: $expanded,
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

    private static func allFolders(in nodes: [NoteTree.Node]) -> Set<String> {
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
                    openBoardPath: openBoardPath,
                    onOpen: onOpen
                )
            }
        } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: isExpanded.wrappedValue ? "folder" : "folder.fill")
                    .foregroundStyle(theme.color(.accentPrimary))
                Text(node.name).themedText(.body).lineLimit(1)
                Spacer(minLength: theme.spacing(.xs))
                Text("\(node.noteCount)").themedText(.caption, color: .textTertiary)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Cartella \(node.name), \(node.noteCount) Workspace")
        }
        .accessibilityIdentifier("workspace-folder-\(node.id)")
    }

    private var boardRow: some View {
        let isOpen = node.id == openBoardPath
        return Button { onOpen(node.id) } label: {
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
