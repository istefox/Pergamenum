import SwiftUI

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D11 and §D12, plan
// docs/plans/contenitore.md, Task 7 - R-16, R-17, R-20, R-25, R-27; mockup 1a, 1d, 1e.

/// The selected document: its preview and fields, and every catalogue action (R-27). Each edit
/// is one guarded write through `ContenitoreInspectorModel`; a refusal reloads the fields from
/// the file rather than overwriting it (R-16).
struct ContenitoreInspector: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(ContenitoreController.self) private var contenitore
    let actions: ContenitoreCommandActions

    var body: some View {
        Group {
            if let selection = contenitore.selection, let session = vault.session, session.exists(selection) {
                ContenitoreInspectorContent(schedaPath: selection, actions: actions)
                    .id(selection)
            } else {
                Text("Nessun documento selezionato")
                    .themedText(.body, color: .textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.color(.backgroundSecondary))
        .accessibilityIdentifier("contenitore-inspector")
    }
}

private struct ContenitoreInspectorContent: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(ContenitoreController.self) private var contenitore
    let schedaPath: String
    let actions: ContenitoreCommandActions

    @State private var newTag = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case date
        case description
        case tag
    }

    /// The controller's edit of this scheda: what is typed lives there, not in this view's
    /// `@State`, so it outlives the view (`ContenitoreEditor`). Nil for the moment before
    /// `.task` has opened it.
    private var editor: ContenitoreEditor? {
        contenitore.editor?.schedaPath == schedaPath ? contenitore.editor : nil
    }

    private var row: ContenitoreRow? {
        guard let session = vault.session, let record = session.index.note(at: schedaPath) else { return nil }
        return ContenitoreListModel.row(
            for: record, root: contenitore.root, fileExists: session.exists,
            status: contenitore.extractionStatus(sha256:)
        )
    }

    var body: some View {
        let row = self.row
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                Text("DOCUMENTO").themedText(.caption, color: .textTertiary)
                if let row, row.isFileMissing {
                    Text("file mancante · «\(row.filePath.map { ($0 as NSString).lastPathComponent } ?? row.name)» "
                        + "non è più accanto alla sua scheda.")
                        .themedText(.caption, color: .taskOverdue)
                        .accessibilityIdentifier("contenitore-inspector-file-missing")
                }
                if let row { ContenitoreThumbnail(row: row, width: 280).frame(height: 180) }
                if row?.isInbox == true { actionButton(.classify) }
                field("NOME") {
                    Text(row?.name ?? "").themedText(.body)
                    if let row { Text(fileLine(row)).themedText(.caption, color: .textSecondary) }
                }
                field("DATA") {
                    TextField("AAAA-MM-GG", text: binding(\.dateText, default: ""))
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .date)
                        .onSubmit { editor?.commitDate() }
                        .accessibilityIdentifier("contenitore-inspector-date")
                }
                field("SOTTOCONTENITORE") { containerMenu(row) }
                field("COLORE") { colourPicker }
                field("TAG") { tagEditor }
                field("DESCRIZIONE") {
                    TextEditor(text: binding(\.draft.description, default: ""))
                        .font(theme.font(.body))
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                        .background(theme.color(.surfaceEntry), in: RoundedRectangle(cornerRadius: theme.radius(.control)))
                        .focused($focusedField, equals: .description)
                        .accessibilityIdentifier("contenitore-inspector-description")
                }
                if let problem = editor?.problem {
                    Text(problem).themedText(.caption, color: .taskOverdue)
                }
                actionList(isInbox: row?.isInbox ?? false)
            }
            .padding(theme.spacing(.l))
        }
        // The reload keys on the landed generation as well as the selection (ADR-0068 §D16), so
        // a write that lands while the inspector is open (`ClassificaSheet` writes through its
        // own model) reaches the fields and the hash the next edit is guarded by.
        .task(id: contenitore.inspectorKey(for: schedaPath)) { contenitore.openEditor(for: schedaPath) }
        .onChange(of: focusedField) { old, _ in
            if old == .description { editor?.requestSave() }
            if old == .date { editor?.commitDate() }
        }
        // The edit is the controller's, so leaving the pane loses nothing: this only asks it to
        // be written now rather than at the next selection change or quit.
        .onDisappear { Task { await contenitore.settleEditing() } }
    }

    /// A binding onto one of the editor's fields, `default` while the editor is not open yet.
    private func binding<Value>(
        _ keyPath: ReferenceWritableKeyPath<ContenitoreEditor, Value>, default fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { editor?[keyPath: keyPath] ?? fallback },
            set: { editor?[keyPath: keyPath] = $0 }
        )
    }

    // MARK: - Fields

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text(title).themedText(.caption, color: .textTertiary)
            content()
        }
    }

    private func fileLine(_ row: ContenitoreRow) -> String {
        var parts = [row.kind]
        if let path = row.filePath, let url = try? vault.session?.store.url(for: path),
           let size = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.size] as? Int64 {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if !row.originalName.isEmpty { parts.append("originale «\(row.originalName)»") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func containerMenu(_ row: ContenitoreRow?) -> some View {
        let current = row.map { container in
            container.container == contenitore.root
                ? "\(contenitore.root) (radice)"
                : ContenitoreListModel.breadcrumb(of: container.container, root: contenitore.root)
        } ?? ""
        return Menu(current) {
            Button("\(contenitore.root) (radice)") { move(to: contenitore.root) }
            ForEach(ContenitoreListModel.allPaths(contenitore.containers())) { node in
                Button(String(repeating: "    ", count: node.depth + 1) + node.name) { move(to: node.path) }
            }
        }
        .fixedSize()
        .accessibilityIdentifier("contenitore-inspector-container")
    }

    private var colourPicker: some View {
        HStack(spacing: theme.spacing(.s)) {
            ForEach(ContenitoreColour.allCases, id: \.self) { colour in
                Button {
                    editor?.draft.colour = colour
                    editor?.requestSave()
                } label: {
                    ContenitoreColourDot(colour: colour)
                        .padding(3)
                        .overlay(Circle().strokeBorder(
                            theme.color(.accentPrimary), lineWidth: editor?.draft.colour == colour ? 2 : 0
                        ))
                }
                .buttonStyle(.plain)
                .help(colour.displayName)
                .accessibilityIdentifier("contenitore-inspector-colour-\(colour.rawValue)")
            }
            Button("nessuno") {
                editor?.draft.colour = nil
                editor?.requestSave()
            }
            .buttonStyle(.link)
        }
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            ForEach(editor?.draft.tags ?? [], id: \.self) { tag in
                HStack(spacing: theme.spacing(.xs)) {
                    Text(tag.description).themedText(.caption)
                    // `type-note` stays: every scheda is a note, and the linter asks for it.
                    if tag != Tag(namespace: .type, value: "note") {
                        Button {
                            editor?.draft.tags.removeAll { $0 == tag }
                            editor?.requestSave()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .help("Togli \(tag.description)")
                        .accessibilityLabel("Togli \(tag.description)")
                    }
                }
            }
            TextField("aggiungi…", text: $newTag)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .tag)
                .onSubmit(addTag)
                .accessibilityIdentifier("contenitore-inspector-add-tag")
        }
    }

    private func actionList(isInbox: Bool) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            ForEach(ContenitoreCommand.inspectorActions(isInbox: isInbox).filter { !(isInbox && $0 == .classify) }, id: \.self) { command in
                actionButton(command)
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ command: ContenitoreCommand) -> some View {
        if command == .moveTo {
            ContenitoreMoveMenu(schedaPath: schedaPath, actions: actions)
                .fixedSize()
        } else {
            Button {
                actions.run(command, on: schedaPath)
            } label: {
                Label(command.title, systemImage: command.symbol)
            }
            .buttonStyle(.link)
            .disabled(!actions.canRun(command, on: schedaPath))
            .accessibilityIdentifier(command.identifier)
        }
    }

    // MARK: - Writes

    private func addTag() {
        guard let editor else { return }
        let text = newTag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return }
        guard let tag = Tag(text) else {
            editor.report("«\(text)» non è un tag valido.")
            return
        }
        newTag = ""
        guard !editor.draft.tags.contains(tag) else { return }
        editor.draft.tags.append(tag)
        editor.requestSave()
    }

    private func move(to container: String) {
        Task { await actions.move(schedaPath, toContainer: container) }
    }
}
