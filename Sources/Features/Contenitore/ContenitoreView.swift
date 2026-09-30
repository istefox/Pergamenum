import SwiftUI

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D11, plan
// docs/plans/contenitore.md, Task 7 - R-13, R-14, R-15, R-22, R-25; mockup 1a-1h.

/// A vault-relative path as a sheet's item.
struct ContenitorePathItem: Identifiable, Equatable {
    let id: String
}

/// The Contenitore pane: the container column (230 pt), the documents, and the inspector
/// (310 pt), the mockup's three columns beside the app's sidebar.
struct ContenitoreView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation
    @Environment(ContenitoreController.self) private var contenitore

    private var actions: ContenitoreCommandActions {
        ContenitoreCommandActions(vault: vault, navigation: navigation, contenitore: contenitore)
    }

    var body: some View {
        let actions = self.actions
        let rows = ContenitoreDocuments.rows(vault: vault, contenitore: contenitore)
        HStack(spacing: 0) {
            ContenitoreSidebar(actions: actions)
                .frame(width: 230)
            Divider()
            ContenitoreDocuments(rows: rows, actions: actions)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            ContenitoreInspector(actions: actions)
                .frame(width: 310)
        }
        .background(theme.color(.backgroundPrimary))
        .modifier(ContenitoreSheets(actions: actions))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contenitore-pane")
    }
}

/// The sheets and the one dialog the commands present, over the whole pane.
private struct ContenitoreSheets: ViewModifier {
    @Environment(ContenitoreController.self) private var contenitore
    let actions: ContenitoreCommandActions

    func body(content: Content) -> some View {
        content
            .sheet(item: item(\.classifying)) { item in
                ClassificaSheet(schedaPath: item.id, actions: actions)
            }
            .sheet(item: item(\.renaming)) { item in
                ContenitoreNameSheet(
                    title: "Rinomina documento",
                    initial: NoteName.title(fromFileName: (item.id as NSString).lastPathComponent),
                    confirm: "Rinomina",
                    validate: { NoteName.validate($0).isEmpty ? nil : "Nome non valido." }
                ) { name in
                    await actions.rename(item.id, to: name) ? nil : "Il documento non è stato rinominato."
                }
            }
            .sheet(item: item(\.moving)) { item in
                ContenitoreMoveSheet(schedaPath: item.id, actions: actions)
            }
            .sheet(item: item(\.creatingContainerIn)) { item in
                ContenitoreNameSheet(
                    title: "Nuovo sottocontenitore",
                    initial: "",
                    confirm: "Crea",
                    validate: ContenitoreCommandActions.refusal(forContainerName:)
                ) { name in
                    await actions.createContainer(named: name, in: item.id)
                }
            }
            // `presenting:`, never a read of `trashing` inside the button (CLAUDE.md, the
            // confirmation-dialog rule): pressing the button dismisses the dialog first.
            .confirmationDialog(
                ContenitoreCommand.trash.title,
                isPresented: Binding(
                    get: { contenitore.trashing != nil },
                    set: { if !$0 { contenitore.trashing = nil } }
                ),
                presenting: contenitore.trashing
            ) { path in
                Button(ContenitoreCommand.trash.title, role: .destructive) {
                    Task { await actions.trash(path) }
                }
            } message: { path in
                Text("«\(NoteName.title(fromFileName: (path as NSString).lastPathComponent))» e il suo file "
                    + "vanno insieme nel Cestino del Finder.")
            }
    }

    private func item(
        _ keyPath: ReferenceWritableKeyPath<ContenitoreController, String?>
    ) -> Binding<ContenitorePathItem?> {
        Binding(
            get: { contenitore[keyPath: keyPath].map(ContenitorePathItem.init) },
            set: { contenitore[keyPath: keyPath] = $0?.id }
        )
    }
}

/// A one-field sheet: rename a document, name a new or renamed container.
struct ContenitoreNameSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let title: String
    let initial: String
    let confirm: String
    /// The refusal sentence for a name, nil when it may be used.
    let validate: (String) -> String?
    /// Performs the change; a sentence when it failed.
    let perform: (String) async -> String?

    @State private var name = ""
    @State private var problem: String?

    init(
        title: String, initial: String, confirm: String,
        validate: @escaping (String) -> String?, perform: @escaping (String) async -> String?
    ) {
        self.title = title
        self.initial = initial
        self.confirm = confirm
        self.validate = validate
        self.perform = perform
        _name = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(title).themedText(.heading)
            TextField("Nome", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit(commit)
                .accessibilityIdentifier("contenitore-name-field")
            if let problem = problem ?? (name.isEmpty ? nil : validate(name)) {
                Text(problem).themedText(.caption, color: .taskOverdue)
            }
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirm, action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || validate(name) != nil || name == initial)
            }
        }
        .padding(theme.spacing(.l))
    }

    private func commit() {
        guard !name.isEmpty, validate(name) == nil, name != initial else { return }
        Task {
            if let failure = await perform(name) {
                problem = failure
            } else {
                dismiss()
            }
        }
    }
}

/// «Sposta in…» from a surface with no submenu: the root, then every container.
struct ContenitoreMoveSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let schedaPath: String
    let actions: ContenitoreCommandActions

    /// Why the last attempt did not move the document, shown until the next one; the sheet
    /// stays open, `ContenitoreNameSheet`'s rule.
    @State private var problem: String?

    var body: some View {
        let root = actions.contenitore.root
        let nodes = ContenitoreListModel.allPaths(actions.contenitore.containers())
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Sposta in…").themedText(.heading)
            List {
                target(path: root, name: "\(root) (radice)", depth: 0)
                ForEach(nodes) { node in target(path: node.path, name: node.name, depth: node.depth + 1) }
            }
            .frame(width: 320, height: 260)
            if let problem { Text(problem).themedText(.caption, color: .taskOverdue) }
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(theme.spacing(.l))
    }

    private func target(path: String, name: String, depth: Int) -> some View {
        Button {
            Task {
                if await actions.move(schedaPath, toContainer: path) {
                    dismiss()
                } else {
                    problem = "Il documento non è stato spostato."
                }
            }
        } label: {
            Label(name, systemImage: "folder")
                .padding(.leading, CGFloat(depth) * theme.spacing(.m))
        }
        .buttonStyle(.plain)
    }
}
