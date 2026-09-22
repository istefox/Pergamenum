import SwiftUI

/// Creates or edits one category (SPEC "UI flows — Category editor", R-01, R-02): name,
/// slug (proposed from the name, editable only at creation), colour, symbol, description,
/// deadline, parent. Every field writes through `CategoryRegistry.validating(_:version:)`
/// (Task 1's one door, reached here through `VaultController+Categories.swift`) - a
/// refusal is shown and nothing is written, never a second, looser check duplicated in
/// this view.
struct CategoryEditor: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    /// What the sheet is editing - `Identifiable` so `RootView` can host it with
    /// `.sheet(item:)`, the same shape `taskPickingCategory` already uses.
    enum Target: Identifiable, Equatable, Sendable {
        /// A brand-new category, nested under `parent` when it is not nil - the section
        /// header's "+" always passes `nil`; a future "new sub-category" affordance would
        /// pass the row it was opened from.
        case new(parent: String?)
        case editing(Category)

        var id: String {
            switch self {
            case .new(let parent): "new-\(parent ?? "top")"
            case .editing(let category): "editing-\(category.slug)"
            }
        }
    }

    /// A restricted picker (SPEC "Not yet specified" - left to implementation, the same
    /// clause that leaves the colour palette open): eight symbols wide enough to tell
    /// most categories apart at a glance, none of it enforced elsewhere, so a hand-edited
    /// registry naming a ninth still renders it (`Category.symbol` stays a plain
    /// `String?`, unvalidated).
    static let symbolChoices = ["folder", "tag", "briefcase", "house", "book", "flag", "star", "bolt"]

    let target: Target
    let onClose: () -> Void

    @State private var name = ""
    @State private var slug = ""
    /// True until the person edits `slug` themselves - `slug` is "proposed from the name"
    /// (SPEC), not locked to it: typing in the slug field of a brand-new category turns
    /// this off, so a deliberate edit is never overwritten by the next keystroke in `name`.
    @State private var slugFollowsName = true
    @State private var color: CategoryColor = .blu
    @State private var symbol: String?
    @State private var description = ""
    @State private var deadline: CalendarDate?
    @State private var isPickingDeadline = false
    @State private var parent: String?
    @State private var refusal: CategoryRegistry.RefusalReason?

    private var isCreating: Bool {
        if case .new = target { true } else { false }
    }

    private var currentSlug: String? {
        if case .editing(let category) = target { category.slug } else { nil }
    }

    /// Why «Crea» is disabled beyond an empty name, shown under the slug field so a greyed
    /// button is never unexplained (this view's own copy of `CategoryRegistry.validating`'s
    /// `malformedSlug` refusal, surfaced before the press instead of after it). Always nil
    /// while editing: the field is disabled there and the slug already passed validation
    /// once, at creation.
    private var slugProblem: String? {
        Self.slugProblem(slug: slug, isCreating: isCreating)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(isCreating ? "Nuova categoria" : "Modifica categoria").themedText(.title)

            fields

            if let refusal {
                Text(message(for: refusal))
                    .themedText(.caption, color: .taskOverdue)
                    .accessibilityIdentifier("category-editor-refusal")
            }

            HStack {
                Spacer()
                Button("Annulla", action: onClose).keyboardShortcut(.cancelAction)
                Button(isCreating ? "Crea" : "Salva", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(Self.isSaveDisabled(name: name, slug: slug, isCreating: isCreating))
                    .accessibilityIdentifier("category-editor-save")
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 380)
        .background(theme.color(.surfaceCard))
        .onExitCommand(perform: onClose)
        .onAppear(perform: load)
    }

    // MARK: Fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            TextField("Nome", text: $name)
                .onChange(of: name) { _, newValue in
                    if slugFollowsName { slug = Self.proposedSlug(from: newValue) }
                }
                .accessibilityIdentifier("category-editor-name")

            TextField("Slug", text: $slug)
                .disabled(!isCreating)
                .onChange(of: slug) { _, newValue in
                    // Only a person's own edit detaches the proposal - the write `name`'s
                    // own `onChange` just made to this same field must not trip it, or the
                    // slug stops following the name after the very first keystroke.
                    if newValue != Self.proposedSlug(from: name) { slugFollowsName = false }
                }
                .accessibilityIdentifier("category-editor-slug")

            // Suppressed while the name is still empty, so the sheet does not open
            // already showing an error before anyone has typed anything.
            if !name.trimmingCharacters(in: .whitespaces).isEmpty, let slugProblem {
                Text(slugProblem)
                    .themedText(.caption, color: .taskOverdue)
                    .accessibilityIdentifier("category-editor-slug-problem")
            }

            colorField
            symbolField

            TextField("Descrizione", text: $description)
                .accessibilityIdentifier("category-editor-description")

            deadlineField
            parentField
        }
    }

    private var colorField: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text("Colore").themedText(.caption, color: .textTertiary)
            ForEach(CategoryColor.allCases) { candidate in
                Circle()
                    .fill(theme.color(candidate.token))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle().strokeBorder(
                            theme.color(.borderStrong), lineWidth: candidate == color ? 2 : 0
                        )
                    )
                    .onTapGesture { color = candidate }
                    .accessibilityIdentifier("category-editor-color-\(candidate.rawValue)")
            }
        }
    }

    private var symbolField: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text("Simbolo").themedText(.caption, color: .textTertiary)
            Menu {
                Button("Nessuno") { symbol = nil }
                ForEach(Self.symbolChoices, id: \.self) { candidate in
                    Button {
                        symbol = candidate
                    } label: {
                        Label(candidate, systemImage: candidate)
                    }
                }
            } label: {
                Image(systemName: symbol ?? "questionmark.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityIdentifier("category-editor-symbol")
        }
    }

    private var deadlineField: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text("Scadenza").themedText(.caption, color: .textTertiary)
            Button(deadline?.italianForm ?? "Nessuna") { isPickingDeadline = true }
                .buttonStyle(.plain)
                .foregroundStyle(theme.color(.accentPrimary))
                .accessibilityIdentifier("category-editor-deadline")
                .popover(isPresented: $isPickingDeadline) {
                    VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                        MonthCalendar(
                            selection: $deadline,
                            onPick: { date in
                                deadline = date
                                isPickingDeadline = false
                            }
                        )
                        if deadline != nil {
                            Button("Rimuovi scadenza") {
                                deadline = nil
                                isPickingDeadline = false
                            }
                        }
                    }
                    .padding(theme.spacing(.m))
                }
        }
    }

    /// Every top-level category but this one (SPEC "Data model": "must name a top-level
    /// category"). A category that itself has children can still be offered here - the
    /// registry's own validator refuses the edit if giving it a parent would leave its
    /// children pointing at a parent that is no longer top-level (`parentNotTopLevel`),
    /// which is the one door every mutation goes through anyway (`CategoryRegistry
    /// .validating`), so this picker does not need to re-derive that rule to stay honest.
    private var parentOptions: [Category] {
        vault.categories.entries.filter { $0.parent == nil && $0.slug != currentSlug }
    }

    private var parentField: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text("Categoria superiore").themedText(.caption, color: .textTertiary)
            Picker("", selection: $parent) {
                Text("Nessuna").tag(String?.none)
                ForEach(parentOptions) { candidate in
                    Text(candidate.name).tag(String?.some(candidate.slug))
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("category-editor-parent")
        }
    }

    // MARK: Loading and saving

    private func load() {
        switch target {
        case .new(let initialParent):
            parent = initialParent
        case .editing(let category):
            name = category.name
            slug = category.slug
            slugFollowsName = false
            color = CategoryColor(rawValue: category.color) ?? .blu
            symbol = category.symbol
            description = category.description ?? ""
            deadline = category.deadline
            parent = category.parent
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDescription = trimmedDescription.isEmpty ? nil : trimmedDescription

        switch target {
        case .new:
            let siblingOrders = vault.categories.entries.filter { $0.parent == parent }.map(\.order)
            let category = Category(
                slug: slug, name: trimmedName, color: color.rawValue, symbol: symbol,
                description: resolvedDescription, deadline: deadline, parent: parent,
                order: (siblingOrders.max() ?? -1) + 1
            )
            refuseOrClose(vault.createCategory(category))
        case .editing(let original):
            let updated = Category(
                slug: original.slug, name: trimmedName, color: color.rawValue, symbol: symbol,
                description: resolvedDescription, deadline: deadline, parent: parent,
                order: original.order, archived: original.archived
            )
            refuseOrClose(vault.updateCategory(updated))
        }
    }

    private func refuseOrClose(_ outcome: CategoryRegistry.RefusalReason?) {
        if let outcome {
            refusal = outcome
        } else {
            onClose()
        }
    }

    private func message(for reason: CategoryRegistry.RefusalReason) -> String {
        switch reason {
        case .malformedSlug(let slug): slug.isEmpty ? "lo slug non può essere vuoto" : "slug non valido: \(slug)"
        case .duplicateSlug(let slug): "esiste già una categoria con slug «\(slug)»"
        case .unknownParent(let slug): "la categoria superiore «\(slug)» non esiste"
        case .parentNotTopLevel(let slug): "«\(slug)» non è una categoria di primo livello"
        case .parentIsSelf(let slug): "una categoria non può essere superiore a se stessa: \(slug)"
        case .registryUnreadable: "il registro delle categorie non è leggibile: nessuna modifica viene salvata"
        }
    }

    /// Why «Crea» should stay disabled, in Italian, or nil when the slug is fine - the same
    /// grammar `CategoryRegistry.validating` enforces (`Tag.isWellFormedValue`), surfaced
    /// before the press instead of only after it as `message(for:)`'s `.malformedSlug` does.
    /// Always nil while editing: the slug field is disabled there and already valid.
    static func slugProblem(slug: String, isCreating: Bool) -> String? {
        guard isCreating else { return nil }
        guard !slug.isEmpty else { return "inserisci uno slug" }
        guard Tag.isWellFormedValue(slug) else { return "solo minuscole, cifre e trattini singoli" }
        return nil
    }

    /// Whether «Crea»/«Salva» should be disabled (ADR-0053 §D2 seam #9): an empty name, or
    /// a slug problem while creating. The trim is `.whitespaces`, not
    /// `.whitespacesAndNewlines` - the same trim `fields`'s own empty-name check at `:121`
    /// uses to gate the problem text, and it is left alone: it gates a different thing.
    static func isSaveDisabled(name: String, slug: String, isCreating: Bool) -> Bool {
        name.trimmingCharacters(in: .whitespaces).isEmpty || slugProblem(slug: slug, isCreating: isCreating) != nil
    }

    /// A first proposal for the slug field (SPEC "Data model": "slug ... proposed from
    /// the name"): lowercased, diacritics folded, every run of characters outside
    /// `Tag.isWellFormedValue`'s grammar collapsed to one hyphen, no leading or trailing
    /// hyphen. Only ever a proposal - `save()` still refuses through the real validator,
    /// so a name that folds to nothing (all punctuation) shows that refusal rather than
    /// silently accepting an empty slug.
    static func proposedSlug(from name: String) -> String {
        let folded = name.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        var slug = ""
        var lastWasHyphen = true
        for scalar in folded.unicodeScalars {
            if allowed.contains(scalar) {
                slug.unicodeScalars.append(scalar)
                lastWasHyphen = false
            } else if !lastWasHyphen {
                slug.append("-")
                lastWasHyphen = true
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug
    }
}
