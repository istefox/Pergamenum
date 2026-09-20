import SwiftUI

/// The "Categorie" section of the Attività sidebar (SPEC "Sidebar", ADR-0047 §D6, R-04,
/// R-05): registered top-level rows with their children beneath a hand-drawn chevron, an
/// implicit row for every `#project-*` value the registry does not know about, and the
/// archived ones tucked inside a collapsed "Archiviate" group.
///
/// **Flat rows, never `DisclosureGroup`** (ADR-0024, CLAUDE.md "Working agreements"): the
/// section sits in the same hand-rolled `VStack`/`ForEach`/`.onTapGesture` shape
/// `TaskViewSidebar` already draws its five rows with - not a `List`, so a
/// `DisclosureGroup`'s label failing to satisfy a `List(selection:)` binding is not even
/// the trap here, but drawing the chevron by hand keeps every row, expanded or not,
/// behaving exactly the same way (`WorkspaceRow`'s own reasoning, ADR-0024 §D3).
struct CategorySidebarSection: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation

    @Binding var selection: TaskPaneSelection

    /// Which top-level rows show their children (ADR-0047 §D6's flat recursion, restated
    /// for depth two: nothing here ever nests past one indent).
    @State private var expandedParents: Set<String> = []
    @State private var isArchivedExpanded = false

    var body: some View {
        let registry = vault.categories
        let implicitSlugs = vault.index.implicitCategories(registry: registry).sorted()
        let archived = registry.entries.filter(\.archived).sorted { $0.order < $1.order }

        return VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            header

            ForEach(registry.assignableGroups, id: \.parent.slug) { group in
                row(group.parent, indented: false, hasChildren: !group.children.isEmpty)
                if !group.children.isEmpty, expandedParents.contains(group.parent.slug) {
                    ForEach(group.children) { child in
                        row(child, indented: true, hasChildren: false)
                    }
                }
            }

            ForEach(implicitSlugs, id: \.self) { slug in
                implicitRow(slug)
            }

            if !archived.isEmpty {
                archivedGroup(archived)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("CATEGORIE").themedText(.caption, color: .textTertiary)
            Spacer()
            Button {
                navigation.categoryEditorTarget = .new(parent: nil)
            } label: {
                Image(systemName: "plus.circle").themedText(.caption, color: .accentPrimary)
            }
            .buttonStyle(.plain)
            .help("Nuova categoria")
            .accessibilityIdentifier("category-add-button")
        }
    }

    // MARK: Registered rows

    private func row(_ category: Category, indented: Bool, hasChildren: Bool) -> some View {
        // Archived rows accept neither drag: dropping a task here (assignment) contradicts
        // "never offer an archived category" (CategoryRegistry.swift's own picker rule), and
        // dragging an archived row for reorder/reparent has nothing valid to land on since
        // both mutations only ever operate on the registered, non-archived tree.
        let isArchived = category.archived

        return CategoryRowDropTarget(
            isEnabled: !isArchived,
            onDropTask: { payload in
                await vault.dropTask(
                    sourcePath: payload.path, lineIndex: payload.lineIndex, onCategory: category.slug
                )
            },
            onDropCategory: { payload in applyCategoryDrop(payload, ontoTarget: category.slug) },
            content: {
                let base = rowLabel(category, indented: indented, hasChildren: hasChildren)
                if isArchived {
                    base
                } else {
                    base.draggable(CategoryDragPayload(slug: category.slug).text)
                }
            }
        )
        .onTapGesture { selection = .category(category.slug) }
        .accessibilityIdentifier("category-row-\(category.slug)")
        .contextMenu { contextMenu(category) }
    }

    /// The label content shared by every registered row - its own function so `row(_:...)`
    /// stays inside the length SwiftLint asks for, same reason `disclosureButton` is one.
    private func rowLabel(_ category: Category, indented: Bool, hasChildren: Bool) -> some View {
        let isSelected = selection.categorySlug == category.slug
        let progress = vault.index.progress(ofCategory: category.slug, registry: vault.categories)
        let openCount = progress.total - progress.done

        return HStack(spacing: theme.spacing(.xs)) {
            if hasChildren {
                disclosureButton(for: category.slug)
            } else {
                // Height pinned as well as width: `Color` takes any height it is offered,
                // and this stack sits inside a bounded one (the sidebar `VStack`, not a
                // `ScrollView`), so leaving it free lets the row swallow the leftover space
                // meant for `TaskViewSidebar`'s trailing `Spacer()`.
                Color.clear.frame(width: 10, height: 1)
            }

            Circle()
                .fill(theme.color(category.colorToken))
                .frame(width: 8, height: 8)

            if let symbol = category.symbol {
                Image(systemName: symbol).themedText(.caption, color: .textTertiary)
            }

            Text(category.name)
                .themedText(.body, color: isSelected ? .textPrimary : .textSecondary)
                .lineLimit(1)

            Spacer()

            if progress.total > 0 {
                CategoryProgressRing(progress: progress)
            }
            if openCount > 0 {
                Text("\(openCount)").themedText(.caption, color: .textTertiary)
            }
        }
        .padding(.leading, indented ? theme.spacing(.l) : theme.spacing(.s))
        .padding(.trailing, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .background(isSelected ? theme.color(.accentMuted) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .contentShape(Rectangle())
    }

    /// A category row dropped onto another one (R-01): resolves the pair against the live
    /// registry through `CategoryDropResolver` and, when it names a move, calls the one
    /// session method for it - a refusal from either is ignored here exactly as the
    /// existing task-onto-category drop above ignores one from `dropTask`.
    private func applyCategoryDrop(_ payload: CategoryDragPayload, ontoTarget targetSlug: String) {
        guard let action = CategoryDropResolver.resolve(
            dragged: payload.slug, ontoTarget: targetSlug, in: vault.categories
        ) else { return }
        switch action {
        case .reparent(let dragged, let parent):
            vault.reparentCategory(dragged, to: parent)
        case .reorder(let parent, let slugs):
            vault.reorderCategories(slugs, parent: parent)
        }
    }

    @ViewBuilder
    private func contextMenu(_ category: Category) -> some View {
        Button("Modifica…") { navigation.categoryEditorTarget = .editing(category) }
        Button(vault.index.homeNote(ofCategory: category.slug) == nil ? "Collega una nota…" : "Cambia nota…") {
            navigation.categoryLinkingNote = .init(slug: category.slug, name: category.name)
        }
        if category.archived {
            Button("Riattiva") { vault.unarchiveCategory(category.slug) }
        } else {
            Button("Archivia") { vault.archiveCategory(category.slug) }
        }
        Divider()
        Button("Elimina", role: .destructive) { vault.deleteCategory(category.slug) }
    }

    private func toggle(_ slug: String) {
        if expandedParents.contains(slug) {
            expandedParents.remove(slug)
        } else {
            expandedParents.insert(slug)
        }
    }

    /// The hand-drawn chevron a top-level row with children carries (ADR-0024 §D3): its
    /// own function so `row(_:indented:hasChildren:)` stays inside the length SwiftLint
    /// asks for, the same reason `TaskListControls` is its own view.
    private func disclosureButton(for slug: String) -> some View {
        Button { toggle(slug) } label: {
            Image(systemName: expandedParents.contains(slug) ? "chevron.down" : "chevron.right")
                .themedText(.caption, color: .textTertiary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("category-disclosure-\(slug)")
    }

    // MARK: Implicit rows (R-04)

    /// A `#project-*` value no registry entry names, muted rather than styled like a
    /// registered row - the "Registra" affordance is the row's whole point, and a colour
    /// dot or a progress ring here would suggest a category that does not yet exist.
    private func implicitRow(_ slug: String) -> some View {
        let isSelected = selection.categorySlug == slug
        return HStack(spacing: theme.spacing(.xs)) {
            Color.clear.frame(width: 10, height: 1)
            Text(slug)
                .themedText(.body, color: isSelected ? .textSecondary : .textTertiary)
                .lineLimit(1)
            Spacer()
            Button("Registra") {
                vault.promoteImplicitCategory(slug, color: CategoryColor.grigio.rawValue)
            }
            .buttonStyle(.plain)
            .themedText(.caption, color: .accentPrimary)
            .accessibilityIdentifier("category-promote-\(slug)")
        }
        .padding(.leading, theme.spacing(.s))
        .padding(.trailing, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .background(isSelected ? theme.color(.accentMuted) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { selection = .category(slug) }
        .accessibilityIdentifier("category-implicit-row-\(slug)")
    }

    // MARK: Archived (R-07)

    private func archivedGroup(_ archived: [Category]) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Button {
                isArchivedExpanded.toggle()
            } label: {
                HStack(spacing: theme.spacing(.xs)) {
                    Image(systemName: isArchivedExpanded ? "chevron.down" : "chevron.right")
                        .themedText(.caption, color: .textTertiary)
                    Text("Archiviate").themedText(.caption, color: .textTertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("category-archived-disclosure")

            if isArchivedExpanded {
                ForEach(archived) { category in
                    row(category, indented: category.parent != nil, hasChildren: false)
                }
            }
        }
    }
}

/// A category row's drop target: takes either a dragged task (assigning it to this
/// category, ADR-0047 §D8/§D9's existing gesture) or a dragged category row (reordering or
/// reparenting it, R-01's gap closed by this fix), disambiguated by which payload the
/// dropped string decodes as - `TaskDragPayload`'s two-part grammar first, since that is
/// the pre-existing contract, and `CategoryDragPayload` only once that fails. Not
/// `TaskDropTarget` itself (`Sources/Features/Today/TaskDrag.swift`): that type is shared by
/// four other surfaces that never carry a category payload, so widening it here would widen
/// it there too.
private struct CategoryRowDropTarget<Content: View>: View {
    @Environment(\.theme) private var theme

    /// False for an archived row (R-07/`CategoryRegistry.assignableGroups`'s own "never offer
    /// an archived category" rule): it accepts neither a dropped task nor a dropped category
    /// row, since both mutations only ever operate on the registered, non-archived tree.
    var isEnabled = true
    let onDropTask: (TaskDragPayload) async -> Bool
    let onDropCategory: (CategoryDragPayload) -> Void
    @ViewBuilder let content: Content

    @State private var isTargeted = false

    var body: some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                    .stroke(isTargeted ? theme.color(.accentPrimary) : .clear, lineWidth: 1)
            )
            .dropDestination(for: String.self) { payloads, _ in
                guard isEnabled, let text = payloads.first else { return false }
                if let taskPayload = TaskDragPayload(text: text) {
                    Task { @MainActor in _ = await onDropTask(taskPayload) }
                    return true
                }
                guard let categoryPayload = CategoryDragPayload(text: text) else { return false }
                onDropCategory(categoryPayload)
                return true
            } isTargeted: { isTargeted = isEnabled && $0 }
    }
}

/// A small ring reading a `TaskProgress` at a glance (SPEC "Sidebar": "progress ring") -
/// the sidebar row's and the category header's own "how much is done", drawn through
/// tokens only.
struct CategoryProgressRing: View {
    @Environment(\.theme) private var theme

    let progress: TaskProgress

    private var fraction: Double {
        guard progress.total > 0 else { return 0 }
        return Double(progress.done) / Double(progress.total)
    }

    var body: some View {
        ZStack {
            Circle().stroke(theme.color(.borderSubtle), lineWidth: 2)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(theme.color(.accentPrimary), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
        .accessibilityLabel("\(progress.done) di \(progress.total) completati")
        .accessibilityIdentifier("category-progress-ring")
    }
}
