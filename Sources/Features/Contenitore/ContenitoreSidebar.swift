import SwiftUI

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D7 and §D11, plan
// docs/plans/contenitore.md, Task 7 - R-14, R-19; mockup 1a and 1h.

/// The pane's own column: «Tutti», «Da classificare» with its count, and the sub-containers as
/// flat recursive rows (ADR-0024: a `DisclosureGroup` label is not a `List` row, so it could
/// never be selected). Year folders never appear.
struct ContenitoreSidebar: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(ContenitoreController.self) private var contenitore
    @Environment(\.undoManager) private var undoManager
    let actions: ContenitoreCommandActions

    /// Collapsed rather than expanded: a tree opens fully expanded, as the mockup draws it.
    @State private var collapsed: Set<String> = []
    @State private var renamingContainer: ContenitorePathItem?
    @State private var trashingContainer: String?

    var body: some View {
        let tree = contenitore.containers()
        let all = allRows
        VStack(spacing: 0) {
            HStack {
                Text("Contenitore").themedText(.heading)
                Spacer()
                Button {
                    contenitore.creatingContainerIn = DocumentoCommands.parent(of: contenitore)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("Nuovo sottocontenitore…")
                .accessibilityLabel("Nuovo sottocontenitore…")
                .accessibilityIdentifier("contenitore-new-container")
            }
            .padding(.horizontal, theme.spacing(.m))
            .padding(.vertical, theme.spacing(.m))
            List(selection: scope) {
                scopeRow("Tutti", symbol: "archivebox", count: all.count, highlighted: false)
                    .tag(ContenitoreScope.all)
                scopeRow("Da classificare", symbol: "tray.and.arrow.down", count: inboxCount, highlighted: inboxCount > 0)
                    .accessibilityIdentifier("contenitore-inbox")
                    .tag(ContenitoreScope.inbox)
                Section("Sottocontenitori") {
                    if tree.isEmpty {
                        Text("Nessun sottocontenitore. «＋» ne crea uno.")
                            .themedText(.caption, color: .textTertiary)
                    }
                    ForEach(ContenitoreListModel.flattened(tree, expanded: expanded(tree))) { node in
                        containerRow(node, count: ContenitoreListModel.count(of: all, in: node.path), tree: tree)
                            .tag(ContenitoreScope.container(node.path))
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Divider()
            footer
        }
        .background(theme.color(.backgroundSecondary))
        .onChange(of: tree, initial: true) { _, current in contenitore.dropVanishedScope(in: current) }
        .sheet(item: $renamingContainer) { item in
            ContenitoreNameSheet(
                title: "Rinomina sottocontenitore",
                initial: (item.id as NSString).lastPathComponent,
                confirm: "Rinomina",
                validate: ContenitoreCommandActions.refusal(forContainerName:)
            ) { name in
                await actions.renameContainer(item.id, to: name)
            }
        }
        .confirmationDialog(
            "Sposta nel Cestino",
            isPresented: Binding(get: { trashingContainer != nil }, set: { if !$0 { trashingContainer = nil } }),
            presenting: trashingContainer
        ) { path in
            Button("Sposta nel Cestino", role: .destructive) { Task { await actions.trashContainer(path) } }
        } message: { path in
            Text("«\((path as NSString).lastPathComponent)» e tutto quello che contiene vanno nel Cestino del Finder.")
        }
    }

    private var scope: Binding<ContenitoreScope?> {
        Binding(get: { contenitore.scope }, set: { if let new = $0 { contenitore.scope = new } })
    }

    /// Every document under the root, unfiltered, for the counts.
    private var allRows: [ContenitoreRow] {
        guard let session = vault.session else { return [] }
        return ContenitoreListModel.rows(
            index: session.index, root: contenitore.root, fileExists: { _ in true },
            status: { _ in nil }, text: { _ in nil }
        )
    }

    private var inboxCount: Int {
        guard let session = vault.session else { return 0 }
        return ContenitoreListModel.inboxCount(index: session.index, root: contenitore.root)
    }

    private func expanded(_ tree: [ContainerNode]) -> Set<String> {
        Set(ContenitoreListModel.allPaths(tree).map(\.path)).subtracting(collapsed)
    }

    private func scopeRow(_ title: String, symbol: String, count: Int, highlighted: Bool) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text("\(count)")
                .themedText(.caption, color: highlighted ? .onAccent : .textSecondary)
                .padding(.horizontal, theme.spacing(.xs))
                .background(
                    Capsule().fill(theme.color(highlighted ? .accentPrimary : .surfaceSunken))
                )
                .accessibilityIdentifier(title == "Tutti" ? "contenitore-all-count" : "contenitore-inbox-count")
        }
    }

    private func containerRow(_ node: ContainerNode, count: Int, tree: [ContainerNode]) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            if node.children.isEmpty {
                Color.clear.frame(width: 12)
            } else {
                Button {
                    if collapsed.contains(node.path) { collapsed.remove(node.path) } else { collapsed.insert(node.path) }
                } label: {
                    Image(systemName: collapsed.contains(node.path) ? "chevron.right" : "chevron.down")
                        .font(theme.font(.caption))
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .help(collapsed.contains(node.path) ? "Espandi" : "Comprimi")
                .accessibilityLabel(collapsed.contains(node.path) ? "Espandi" : "Comprimi")
            }
            Label(node.name, systemImage: "folder")
            Spacer()
            Text("\(count)").themedText(.caption, color: .textSecondary)
        }
        .padding(.leading, CGFloat(node.depth) * theme.spacing(.m))
        .contextMenu {
            Button("Nuovo sottocontenitore…") { contenitore.creatingContainerIn = node.path }
            Button("Rinomina…") { renamingContainer = ContenitorePathItem(id: node.path) }
            Menu("Sposta in…") {
                ForEach(moveTargets(for: node, in: tree), id: \.self) { target in
                    Button(target == contenitore.root ? "\(target) (radice)" : ContenitoreListModel.breadcrumb(
                        of: target, root: contenitore.root
                    )) {
                        Task { await actions.moveContainer(node.path, into: target, undo: undoManager) }
                    }
                }
            }
            Divider()
            Button("Sposta nel Cestino") { trashingContainer = node.path }
        }
        .accessibilityIdentifier("contenitore-container-row")
    }

    /// The root and every container, bar `node`, its descendants and its own parent.
    private func moveTargets(for node: ContainerNode, in tree: [ContainerNode]) -> [String] {
        let parent = (node.path as NSString).deletingLastPathComponent
        return ([contenitore.root] + ContenitoreListModel.allPaths(tree).map(\.path)).filter {
            $0 != parent && $0 != node.path && !$0.hasPrefix(node.path + "/")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Cartella di raccolta").themedText(.caption, color: .textTertiary)
            Text(contenitore.dropFolderDisplay).themedText(.caption, color: .textSecondary)
            Text(status).themedText(.caption, color: contenitore.isDropFolderReadable ? .textTertiary : .taskOverdue)
                .accessibilityIdentifier("contenitore-drop-status")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.spacing(.m))
    }

    private var status: String {
        if contenitore.isIsolated { return "Disattivato per questa sessione" }
        guard contenitore.isDropFolderReadable else { return "Illeggibile · nessun import" }
        guard let last = contenitore.lastImportAt else { return "In ascolto · nessun import" }
        let time = last.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "it_IT"))
        )
        return "In ascolto · ultimo import \(time)"
    }
}
