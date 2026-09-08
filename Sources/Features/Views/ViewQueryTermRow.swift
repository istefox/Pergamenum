import SwiftUI

/// The Filtro row's eight kinds, their pure row → term conversion (ADR-0034 §D11/R-06), and
/// the pickers a row's argument is filled in through — folder, tag, note title, field, date
/// bound. `FolderPickerMenu` is declared here rather than in `ViewQuerySections.swift`
/// because both it and the `path` term row need it (§D11: "declared once, used by both
/// sections, so the two cannot drift").
enum ViewQueryTermRow {
    /// The eight kinds `ViewFilter.Parser.term(name:argument:)` accepts, in its own order.
    enum Kind: String, CaseIterable, Sendable {
        case path, tag, linksTo, linkedFrom, task, has, text, comparison

        /// What the kind picker shows, in the interface's language.
        var label: String {
            switch self {
            case .path: "percorso"
            case .tag: "tag"
            case .linksTo: "collega a"
            case .linkedFrom: "collegata da"
            case .task: "task"
            case .has: "esiste"
            case .text: "testo"
            case .comparison: "confronto"
            }
        }
    }

    /// C7: the only two fields a `comparison` term may name — the parser throws on every
    /// other one (`ViewFilter.swift:186-193`), so the picker restricts rather than validates.
    static let comparisonFields: [ViewField] = [.date, .modified]
    /// R-06: `has()` resolves through `ViewField(rawValue:)`, so every one of the eighteen.
    static let hasFields: [ViewField] = ViewField.allCases

    /// One Filtro row: a kind plus the argument(s) it needs, pure. `term` is the only thing
    /// a caller reads — never a case-by-case switch repeated at the call site.
    ///
    /// `field`/`comparison` only mean something for `.comparison` (C7); `.has` reads its
    /// field out of `argument` instead (`field.rawValue`, matching the parser's own
    /// `has(tasks.open)` spelling), because that is the shape R-06's assertions require.
    struct Value: Equatable, Sendable {
        var kind: Kind
        var argument: String
        var field: ViewField
        var comparison: ViewFilter.Comparison

        init(
            kind: Kind,
            argument: String = "",
            field: ViewField = .modified,
            comparison: ViewFilter.Comparison = .atLeast
        ) {
            self.kind = kind
            self.argument = argument
            self.field = field
            self.comparison = comparison
        }

        /// The term this row encodes, or `nil` when it is not ready to be written yet
        /// (ADR §D7): an empty argument, a `comparison` field outside C7's pair, a date
        /// bound `ViewDateBound.parse` does not accept, or an argument that names neither a
        /// `task()` state nor a `ViewField`.
        var term: ViewFilter? {
            switch kind {
            case .path: argument.isEmpty ? nil : .path(argument)
            case .tag: argument.isEmpty ? nil : .tag(argument)
            case .linksTo: argument.isEmpty ? nil : .linksTo(argument)
            case .linkedFrom: argument.isEmpty ? nil : .linkedFrom(argument)
            case .text: argument.isEmpty ? nil : .text(argument)
            case .task: taskTerm
            case .has: ViewField(rawValue: argument).map(ViewFilter.has)
            case .comparison: comparisonTerm
            }
        }

        private var taskTerm: ViewFilter? {
            switch argument.lowercased() {
            case "open": .task(.open)
            case "done": .task(.done)
            default: nil
            }
        }

        private var comparisonTerm: ViewFilter? {
            guard ViewQueryTermRow.comparisonFields.contains(field),
                  let bound = ViewDateBound.parse(argument)
            else { return nil }
            return .comparison(field, comparison, bound)
        }
    }
}

// MARK: - The row's own control

/// The kind picker plus the control its kind calls for. Used as the "add a term" composer
/// in `ViewQueryFilterSection` — a `path` row is exactly an Ambito row, so Ambito reuses
/// `FolderPickerMenu` directly rather than this whole view (ADR §D11).
struct ViewQueryTermRowView: View {
    @Binding var value: ViewQueryTermRow.Value

    var body: some View {
        HStack(alignment: .top) {
            Picker("termine", selection: $value.kind) {
                ForEach(ViewQueryTermRow.Kind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 140)

            argumentControl
        }
        .onChange(of: value.kind) { _, _ in value.argument = "" }
        .accessibilityIdentifier("view-query-term-row")
    }

    @ViewBuilder
    private var argumentControl: some View {
        switch value.kind {
        case .path:
            FolderPickerMenu(glob: $value.argument)
        case .tag:
            TagPickerMenu(glob: $value.argument)
        case .linksTo, .linkedFrom:
            NoteTitlePicker(title: $value.argument)
        case .task:
            TaskStatePicker(argument: $value.argument)
        case .has:
            FieldPickerMenu(fields: ViewQueryTermRow.hasFields, field: hasFieldBinding)
        case .text:
            TextField("testo", text: $value.argument)
                .textFieldStyle(.roundedBorder)
        case .comparison:
            comparisonControl
        }
    }

    private var comparisonControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                FieldPickerMenu(fields: ViewQueryTermRow.comparisonFields, field: $value.field)
                Picker("simbolo", selection: $value.comparison) {
                    ForEach(Self.comparisonSymbols, id: \.self) { symbol in
                        Text(symbol.rawValue).tag(symbol)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            DateBoundControl(argument: $value.argument)
        }
    }

    /// `ViewFilter.Comparison` is not `CaseIterable` (it lives in `Sources/Core`, out of this
    /// task's scope), so the five symbols the parser's own lexer accepts are named here.
    private static let comparisonSymbols: [ViewFilter.Comparison] = [
        .atLeast, .atMost, .greaterThan, .lessThan, .equalTo,
    ]

    private var hasFieldBinding: Binding<ViewField> {
        Binding(
            get: { ViewField(rawValue: value.argument) ?? ViewQueryTermRow.hasFields[0] },
            set: { value.argument = $0.rawValue }
        )
    }
}

// MARK: - Folder (finding 2 / C2): Ambito and the `path` term

/// The flat `Menu` over `vault.folders` this app already uses for "Sposta in…"
/// (`NewNoteComposer.folderPicker`), beside the free-text field a `path()` argument needs
/// since it is a glob, not just a folder name (`path("01 *")` is one of ADR-0009's own
/// examples). Declared once, used by `ViewQueryScopeSection` and the `path` term row.
struct FolderPickerMenu: View {
    @Environment(VaultController.self) private var vault
    @Binding var glob: String

    var body: some View {
        HStack {
            Menu {
                ForEach(vault.folders, id: \.self) { folder in
                    Button(folder) { glob = folder }
                }
            } label: {
                Label(glob.isEmpty ? "cartella…" : glob, systemImage: "folder")
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            TextField("percorso o glob", text: $glob)
                .textFieldStyle(.roundedBorder)
        }
        .accessibilityIdentifier("view-query-folder-picker")
    }
}

// MARK: - Tag (finding 3 / C3): the `tag` term

/// `TagBrowserView` is a pane, not a picker (finding 3): only the data it reads is reusable,
/// `vault.index.tagUsage()` grouped by `TagNamespace.allCases`, beside a free-text field for
/// a glob — `tag("status-*")` is the common case a picker with no wildcard row could not say.
struct TagPickerMenu: View {
    @Environment(VaultController.self) private var vault
    @Binding var glob: String

    var body: some View {
        HStack {
            Menu {
                ForEach(TagNamespace.allCases, id: \.self) { namespace in
                    let tags = tagsByNamespace[namespace] ?? []
                    if !tags.isEmpty {
                        Section(namespace.rawValue) {
                            ForEach(tags, id: \.self) { tag in
                                Button(tag.description) { glob = tag.description }
                            }
                        }
                    }
                }
            } label: {
                Label(glob.isEmpty ? "tag…" : glob, systemImage: "tag")
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            TextField("tag o glob", text: $glob)
                .textFieldStyle(.roundedBorder)
        }
        .accessibilityIdentifier("view-query-tag-picker")
    }

    private var tagsByNamespace: [TagNamespace: [Tag]] {
        Dictionary(grouping: vault.index.tagUsage().map(\.tag), by: \.namespace)
    }
}

// MARK: - Note title (finding 4 / C4): `linksTo` / `linkedFrom`

/// `RelatedLinkSheet`'s shape copied, not extracted (ADR §D11) — `RelatedLinkSheet.swift`
/// carries two reason fields and a bidirectional write this row has no use for, so copying
/// costs one small view instead of a refactor of a working sheet. A `TextField` over
/// `vault.index.search(query, limit: 20)` and a `List` of titles.
struct NoteTitlePicker: View {
    @Environment(VaultController.self) private var vault
    @Binding var title: String
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("cerca una nota…", text: $query)
                .textFieldStyle(.roundedBorder)
            List(
                vault.index.search(query, limit: 20), id: \.relativePath,
                selection: Binding(get: { title.isEmpty ? nil : title }, set: { title = $0 ?? "" })
            ) { note in
                Text(note.title).tag(note.title)
            }
            .frame(height: 100)
            .scrollContentBackground(.hidden)
        }
        .accessibilityIdentifier("view-query-note-picker")
    }
}

// MARK: - Field: `has`, and the comparison's field (Ordina/Colonne reuse this later)

/// `ViewField.allCases` (or C7's two-item restriction) shown by `ViewField.label` — the one
/// picker every field-shaped control in the sheet reads from (ADR §D11).
struct FieldPickerMenu: View {
    let fields: [ViewField]
    @Binding var field: ViewField

    var body: some View {
        Picker("campo", selection: $field) {
            ForEach(fields, id: \.self) { candidate in
                Text(candidate.label).tag(candidate)
            }
        }
        .labelsHidden()
        .accessibilityIdentifier("view-query-field-picker")
    }
}

// MARK: - Task state

/// The closed pair `ViewFilter.task` accepts. `argument` rather than `TaskItem.State`
/// directly, since that is what `ViewQueryTermRow.Value` stores for this kind (R-06).
struct TaskStatePicker: View {
    @Binding var argument: String

    var body: some View {
        Picker("stato", selection: $argument) {
            Text("aperto").tag("open")
            Text("fatto").tag("done")
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("view-query-task-picker")
    }
}

// MARK: - Date bound (§D12)

/// Three forms, one segmented control, writing the parser's own spellings —
/// `ViewDateBound.todayKeyword`/`weekStartKeyword` — never the SPEC's Italian words (C1,
/// finding 1). Only the labels a person reads are Italian; the round trip is asserted
/// against `ViewDateBound.text` in `ViewQueryTextTests.swift`.
struct DateBoundControl: View {
    @Binding var argument: String

    private enum Form: String, CaseIterable {
        case day, today, weekStart

        var label: String {
            switch self {
            case .day: "data"
            case .today: "oggi"
            case .weekStart: "inizio settimana"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("forma", selection: formBinding) {
                ForEach(Form.allCases, id: \.self) { form in
                    Text(form.label).tag(form)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            switch currentForm {
            case .day:
                DatePicker("giorno", selection: dayBinding, displayedComponents: .date)
                    .labelsHidden()
            case .today:
                Stepper("oggi meno \(offset) giorni", value: offsetBinding, in: 0...365)
            case .weekStart:
                EmptyView()
            }
        }
        .accessibilityIdentifier("view-query-date-bound")
    }

    private var currentForm: Form {
        if argument == ViewDateBound.weekStartKeyword { return .weekStart }
        if argument == ViewDateBound.todayKeyword
            || argument.hasPrefix("\(ViewDateBound.todayKeyword)-") { return .today }
        return .day
    }

    private var offset: Int {
        guard argument.hasPrefix("\(ViewDateBound.todayKeyword)-"),
              let value = Int(argument.dropFirst(ViewDateBound.todayKeyword.count + 1))
        else { return 0 }
        return value
    }

    private var formBinding: Binding<Form> {
        Binding(
            get: { currentForm },
            set: { form in
                switch form {
                case .day: argument = CalendarDate(Date()).description
                case .today: argument = ViewDateBound.todayKeyword
                case .weekStart: argument = ViewDateBound.weekStartKeyword
                }
            }
        )
    }

    private var offsetBinding: Binding<Int> {
        Binding(
            get: { offset },
            set: { argument = $0 == 0 ? ViewDateBound.todayKeyword : "\(ViewDateBound.todayKeyword)-\($0)" }
        )
    }

    private var dayBinding: Binding<Date> {
        Binding(
            get: { CalendarDate(iso: argument).flatMap(Self.date(from:)) ?? Date() },
            set: { argument = CalendarDate($0).description }
        )
    }

    private static func date(from day: CalendarDate) -> Date? {
        Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
    }
}
