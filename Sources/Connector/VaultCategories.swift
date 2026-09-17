import Foundation

// MARK: - Payload shapes
//
// Kept in this file rather than in `VaultPayloads.swift` (PG-035/ADR-0045's pure code
// motion, applied to a brand-new pair of types rather than an existing one): the two
// share nothing with `VaultPayloads.swift`'s other shapes but the `VaultAPI` namespace,
// and moving them here is what keeps that file under SwiftLint's `file_length` warning
// rather than adding a fourth co-located-but-separate payload file.

/// The two category reads of ADR-0047 §D9 (R-09): the registry, with implicit
/// categories folded in, and one category's rolled-up task set. Both `perg` and
/// `pergamenum-mcp` call these, so neither can quietly answer differently (the same
/// reasoning `VaultReads.swift`'s own header gives).
///
/// **Read-only, deliberately** (SPEC "Decisions": "Connectors read categories, never
/// write them"): no `create`/`update`/`archive`/`promote` counterpart exists here, and
/// none is added by this file.
extension VaultAPI {
    /// One entry of `perg categories` (SPEC "Connector reads": "registry entries with
    /// implicit: true|false, archived flag, parent, progress"). Registered and implicit
    /// categories share this shape - an implicit one carries only its slug, the same
    /// synthesized stand-in `CategoryView` builds for one (`name` equal to `slug`,
    /// `CategoryColor.grigio`), so a caller sees one flat list rather than two.
    struct CategorySummary: Encodable {
        let slug: String
        let name: String
        let color: String
        let symbol: String?
        let description: String?
        let deadline: String?
        let parent: String?
        let order: Int
        let archived: Bool
        let implicit: Bool
        let progress: TaskProgressSummary

        init(_ category: Category, implicit: Bool, progress: TaskProgress) {
            slug = category.slug
            name = category.name
            color = category.color
            symbol = category.symbol
            description = category.description
            deadline = category.deadline?.description
            parent = category.parent
            order = category.order
            archived = category.archived
            self.implicit = implicit
            self.progress = TaskProgressSummary(progress)
        }
    }

    struct TaskProgressSummary: Encodable {
        let done: Int
        let total: Int

        init(_ progress: TaskProgress) {
            done = progress.done
            total = progress.total
        }
    }

    /// `perg category-tasks <slug>` (SPEC "Connector reads": "rolled up, grouped as the
    /// view is"). `groups` is the whole subtree's task set (`rolledUp: true`, the same
    /// set the category view's own progress ring counts) arranged through
    /// `TaskArrangement.groups(_:options:)`, the shared grouping every task list in the
    /// app already reads through - never a second grouping algorithm for the connector.
    struct CategoryTasksPayload: Encodable {
        let slug: String
        let groups: [Group]

        struct Group: Encodable {
            /// Empty when the list is not grouped, same convention `ViewRun.Group.label`
            /// uses for "no heading" - except here it is never `nil`, matching
            /// `TaskGroup.title` itself.
            let label: String
            let tasks: [TaskSummary]
        }
    }
}

// MARK: - Reads

extension VaultAPI {
    /// `categories` (SPEC "Connector reads"): every registered entry, `implicit: false`,
    /// plus one synthesized entry per implicit slug, `implicit: true` - the same
    /// unification `CategorySidebarSection` draws as two `ForEach`s over one list.
    @MainActor
    static func categories(_ session: VaultSession) -> [CategorySummary] {
        let registry = session.categories
        let registered = registry.entries.map { category in
            CategorySummary(
                category, implicit: false,
                progress: session.index.progress(ofCategory: category.slug, registry: registry)
            )
        }
        let implicit = session.index.implicitCategories(registry: registry).sorted().map { slug in
            CategorySummary(
                Category(slug: slug, name: slug, color: CategoryColor.grigio.rawValue),
                implicit: true,
                progress: session.index.progress(ofCategory: slug, registry: registry)
            )
        }
        return registered + implicit
    }

    /// `category-tasks <slug>` (SPEC "Connector reads"): refuses a slug that is neither
    /// registered nor implicit - there is no rolled-up task set to answer with, and a
    /// silent empty list would read as "no open tasks" rather than "no such category".
    ///
    /// Grouping/sorting is the same fixed default `TasksView+List.swift` falls back to
    /// for a category with no stored controls of its own (`TaskListOptions(grouping:
    /// .none, sorting: .schedule)`): the per-category controls a person sets in the app
    /// live in `@AppStorage`, which no connector can reach, so this is the one answer
    /// every caller gets rather than one that silently depends on whichever machine
    /// last had the app open.
    @MainActor
    static func categoryTasks(_ session: VaultSession, slug: String) throws -> CategoryTasksPayload {
        let registry = session.categories
        guard registry.entries.contains(where: { $0.slug == slug })
            || session.index.implicitCategories(registry: registry).contains(slug)
        else {
            throw ConnectorError("«\(slug)» non è una categoria registrata né implicita")
        }

        let tasks = session.index.tasks(inCategory: slug, registry: registry, rolledUp: true)
        let options = TaskListOptions(grouping: .none, sorting: .schedule)
        let groups = TaskArrangement.groups(tasks, options: options)
        return CategoryTasksPayload(
            slug: slug,
            groups: groups.map { CategoryTasksPayload.Group(label: $0.title, tasks: $0.tasks.map(TaskSummary.init)) }
        )
    }
}
