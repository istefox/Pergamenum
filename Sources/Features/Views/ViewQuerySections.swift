import SwiftUI

/// The query builder's seven sections (ADR-0034 §D10), in `ViewBlock`'s own declaration
/// order — `from`, `where`, `sort`, `group`, `render`, `columns`, `limit`.
///
/// Each section is its own type reading and writing `ViewQueryDraft` directly, never a
/// computed property on the sheet (`~/.claude/rules/swift.md`'s one-principal-type rule) —
/// module-internal rather than `private`, since `ViewQueryBuilderSheet.swift` constructs
/// them from a sibling file. Every section shows the draft's current rows with a way to
/// remove one, over the app's design tokens. Ambito and Filtro (R-05/R-06) additionally gain
/// an "add a row" composer wired to `ViewQueryTermRow.swift`'s pickers (ADR §D11) — Ordina,
/// Raggruppa, Colonne and Limite keep Task 5's shell, out of this task's R-05/R-06 scope.

// MARK: - Ambito (`from`)

struct ViewQueryScopeSection: View {
    @Environment(\.theme) private var theme
    @Bindable var draft: ViewQueryDraft
    @State private var newGlob = ""

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("Ambito").themedText(.caption, color: .textTertiary)
            if draft.scope.isEmpty {
                Text("tutto il vault").themedText(.body, color: .textSecondary)
            } else {
                ForEach(Array(draft.scope.enumerated()), id: \.offset) { index, folder in
                    row(folder) { draft.scope.remove(at: index) }
                }
            }
            // R-05: each row an Ambito row adds is exactly a `path` term
            // (`ViewQueryTermRow.Value(kind: .path, …).term`), so the writer's own
            // `or`-join (`ViewQueryText.body(of:)`) needs nothing new here.
            HStack {
                FolderPickerMenu(glob: $newGlob)
                Button("Aggiungi", action: addFolder)
                    .disabled(newGlob.isEmpty)
            }
            .accessibilityIdentifier("view-query-scope-add")
        }
        .accessibilityIdentifier("view-query-scope")
    }

    private func addFolder() {
        guard !newGlob.isEmpty else { return }
        draft.scope.append(newGlob)
        newGlob = ""
    }

    private func row(_ text: String, remove: @escaping () -> Void) -> some View {
        HStack {
            Text(text).themedText(.body)
            Spacer()
            removeButton(action: remove)
        }
    }
}

// MARK: - Filtro (`where`)

struct ViewQueryFilterSection: View {
    @Environment(\.theme) private var theme
    @Bindable var draft: ViewQueryDraft
    @State private var newTerm = ViewQueryTermRow.Value(kind: .path)

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("Filtro").themedText(.caption, color: .textTertiary)
            // R-07: a `where` the row model cannot show (`or`, `not`, a nesting) seeds
            // `rawWhere` rather than `terms` (ADR §D5) — the raw-text fallback is what a
            // person meets the grammar through, validated live via `ViewBlock.parse`.
            if draft.rawWhere != nil {
                TextField(
                    "where",
                    text: Binding(get: { draft.rawWhere ?? "" }, set: { draft.rawWhere = $0 })
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("view-query-where-raw")
            } else {
                if draft.terms.isEmpty {
                    Text("nessun filtro").themedText(.body, color: .textSecondary)
                } else {
                    ForEach(Array(draft.terms.enumerated()), id: \.offset) { index, term in
                        HStack {
                            Text(ViewQueryText.text(of: term)).themedText(.mono, color: .textSecondary)
                            Spacer()
                            removeButton { draft.terms.remove(at: index) }
                        }
                    }
                }
                // R-06: the eight-kind composer (`ViewQueryTermRow.swift`) — a row is
                // appended only once its own `.term` is non-nil (ADR §D7), the same
                // "disabled until valid" convention `ViewQueryBuilderSheet`'s "Fatto"
                // already uses, rather than ever writing an incomplete term into the draft.
                HStack(alignment: .top) {
                    ViewQueryTermRowView(value: $newTerm)
                    Button("Aggiungi", action: addTerm)
                        .disabled(newTerm.term == nil)
                }
                .accessibilityIdentifier("view-query-term-add")
            }
        }
        .accessibilityIdentifier("view-query-filter")
    }

    private func addTerm() {
        guard let term = newTerm.term else { return }
        draft.terms.append(term)
        newTerm = ViewQueryTermRow.Value(kind: newTerm.kind)
    }
}

// MARK: - Ordina (`sort`)

struct ViewQuerySortSection: View {
    @Environment(\.theme) private var theme
    @Bindable var draft: ViewQueryDraft

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("Ordina").themedText(.caption, color: .textTertiary)
            if draft.sort.isEmpty {
                Text("ordine predefinito").themedText(.body, color: .textSecondary)
            } else {
                ForEach(Array(draft.sort.enumerated()), id: \.offset) { index, key in
                    HStack {
                        Text(key.field.label).themedText(.body)
                        Spacer()
                        Toggle("decrescente", isOn: Binding(
                            get: { draft.sort[index].descending },
                            set: { draft.sort[index].descending = $0 }
                        ))
                        .toggleStyle(.checkbox)
                        removeButton { draft.sort.remove(at: index) }
                    }
                }
            }
        }
        .accessibilityIdentifier("view-query-sort")
    }
}

// MARK: - Raggruppa (`group`) — R-08: shown only for `render: board`

struct ViewQueryGroupSection: View {
    @Environment(\.theme) private var theme
    @Bindable var draft: ViewQueryDraft

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("Raggruppa").themedText(.caption, color: .textTertiary)
            TextField(
                "tag(\"status-*\")",
                text: Binding(
                    get: { groupText },
                    set: { draft.group = $0.isEmpty ? nil : .tag($0) }
                )
            )
            .textFieldStyle(.roundedBorder)
        }
        .accessibilityIdentifier("view-query-group")
    }

    private var groupText: String {
        switch draft.group {
        case .tag(let glob): glob
        case .field(let field): field.rawValue
        case nil: ""
        }
    }
}

// MARK: - Rendering (`render`)

struct ViewQueryRenderSection: View {
    @Environment(\.theme) private var theme
    @Bindable var draft: ViewQueryDraft

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("Rendering").themedText(.caption, color: .textTertiary)
            Picker("Rendering", selection: $draft.render) {
                ForEach(ViewBlock.Renderer.allCases, id: \.self) { renderer in
                    Text(renderer.title).tag(renderer)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
        .accessibilityIdentifier("view-query-render")
    }
}

// MARK: - Colonne (`columns`)

struct ViewQueryColumnsSection: View {
    @Environment(\.theme) private var theme
    @Bindable var draft: ViewQueryDraft

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("Colonne").themedText(.caption, color: .textTertiary)
            if draft.columns.isEmpty {
                Text("predefinite per \(draft.render.title)").themedText(.body, color: .textSecondary)
            } else {
                ForEach(Array(draft.columns.enumerated()), id: \.offset) { index, field in
                    HStack {
                        Text(field.label).themedText(.body)
                        Spacer()
                        removeButton { draft.columns.remove(at: index) }
                    }
                }
            }
        }
        .accessibilityIdentifier("view-query-columns")
    }
}

// MARK: - Limite (`limit`)

struct ViewQueryLimitSection: View {
    @Environment(\.theme) private var theme
    @Bindable var draft: ViewQueryDraft

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("Limite").themedText(.caption, color: .textTertiary)
            TextField("nessun limite", text: $draft.limit)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
        }
        .accessibilityIdentifier("view-query-limit")
    }
}

// MARK: - Shared

/// The one remove control every row-listing section above draws the same way.
@MainActor @ViewBuilder
private func removeButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "xmark.circle").themedText(.caption, color: .textTertiary)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Rimuovi")
}
