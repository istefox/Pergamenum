import SwiftUI

/// A category's own pane (SPEC "UI flows — Category view", R-05): a header (name,
/// description, deadline, rolled-up progress), the category's direct tasks, then one
/// group per child.
///
/// **The tasks are drawn by the caller's own row, not a second row view.** `TasksView`'s
/// `row(_:isRolledOver:)` (`TasksView+Row.swift`) already carries the selection
/// highlight, the checkbox, the context menu and the due-date sheet every task in this
/// pane needs, and it closes over `TasksView`'s own `@State` (`selectedTaskID`,
/// `addingDueFor`) to do it - state this view has no business holding a second copy of.
/// `TasksView+List.swift`'s `list` passes `row` itself as `taskRow`, so a category task
/// is selectable, completable and right-clickable exactly like every other task in the
/// pane (the same reasoning `project(_:parent:rolledIDs:)` already gives for reusing
/// `row` on a "Progetti" heading).
///
/// `category` is a real registry entry for a registered slug, or a synthesized stand-in
/// (name equal to the slug, `CategoryColor.grigio`) for an implicit one - `isRegistered`
/// tells the header which it got, so an implicit category's header offers "Registra"
/// instead of the description/deadline fields a registry entry alone can carry.
///
/// `options` is the same `TaskListOptions` the five views read (ADR-0013 §D6), stored
/// under this category's own `category:<slug>` key (`TasksView+List.swift`) - grouping
/// and sorting apply to the direct tasks and to each child's, independently of one
/// another, exactly as `TaskArrangement.groups(_:options:)` already arranges a flat list
/// for `list`. A `.subtasks`/"Progetti" grouping renders its parent groups as a plain
/// heading here rather than `list`'s own `DisclosureGroup`-free but still-nested
/// `project(_:parent:rolledIDs:)` row - a deliberately plainer render for one grouping,
/// not a second row view to keep in step with that one.
struct CategoryView<Row: View>: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    let category: Category
    let isRegistered: Bool
    let options: TaskListOptions
    /// A plain closure, not `@ViewBuilder` - it is called once per task rather than once
    /// for a single content block, and `row(_:isRolledOver:)`'s call already returns one
    /// opaque `some View`, so there is nothing here for the builder syntax to combine.
    let taskRow: (TaskItem) -> Row

    var body: some View {
        let registry = vault.categories
        let progress = vault.index.progress(ofCategory: category.slug, registry: registry)
        let direct = TaskArrangement.groups(
            vault.index.tasks(inCategory: category.slug, registry: registry, rolledUp: false),
            options: options
        )
        let children = registry.children(of: category.slug)
            .filter { !$0.archived }
            .sorted { $0.order < $1.order }

        return ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                header(progress: progress)

                ForEach(direct) { group in groupSection(group) }

                ForEach(children) { child in
                    childGroup(child, registry: registry)
                }

                if direct.isEmpty, children.isEmpty {
                    Text("Nessun task in questa categoria")
                        .themedText(.body, color: .textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, theme.spacing(.xl))
                }
            }
            .padding(theme.spacing(.l))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("category-view-\(category.slug)")
    }

    private func groupSection(_ group: TaskGroup) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            if !group.title.isEmpty {
                Text(group.title).themedText(.heading)
            }
            ForEach(group.tasks) { task in taskRow(task) }
        }
    }

    // MARK: Header

    private func header(progress: TaskProgress) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(spacing: theme.spacing(.s)) {
                if let symbol = category.symbol {
                    Image(systemName: symbol).foregroundStyle(theme.color(category.colorToken))
                }
                Text(category.name).themedText(.title)
                Spacer()
                if progress.total > 0 {
                    CategoryProgressRing(progress: progress)
                    Text("\(progress.done)/\(progress.total)")
                        .themedText(.mono, color: .textTertiary)
                        .accessibilityLabel("\(progress.done) di \(progress.total) completati")
                }
                if !isRegistered {
                    Button("Registra") {
                        vault.promoteImplicitCategory(category.slug, color: CategoryColor.grigio.rawValue)
                    }
                    .accessibilityIdentifier("category-view-promote")
                }
            }

            if let description = category.description, !description.isEmpty {
                Text(description).themedText(.body, color: .textSecondary)
            }

            if let deadline = category.deadline {
                Text("Scadenza \(deadline.italianForm)")
                    .themedText(.caption, color: .taskOverdue)
                    .accessibilityIdentifier("category-view-deadline")
            }
        }
    }

    // MARK: Children (SPEC: "then one group per child")

    private func childGroup(_ child: Category, registry: CategoryRegistry) -> some View {
        let groups = TaskArrangement.groups(
            vault.index.tasks(inCategory: child.slug, registry: registry, rolledUp: false), options: options
        )
        return Group {
            if !groups.isEmpty {
                VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                    HStack(spacing: theme.spacing(.xs)) {
                        Circle().fill(theme.color(child.colorToken)).frame(width: 6, height: 6)
                        Text(child.name).themedText(.heading)
                    }
                    ForEach(groups) { group in groupSection(group) }
                }
            }
        }
    }
}
