import Foundation

/// The index-derived facts a category needs (ADR-0047 §D4): the effective category per
/// task, the implicit categories, the rolled-up task set and its progress. `import
/// Foundation` only, no SwiftUI - compiled into both connectors.
extension IndexSnapshot {
    /// The category a task effectively belongs to (SPEC "Task ↔ category"): its own
    /// `#project-*` tag first, else the `pergamenum-category` of the note it lives in,
    /// else none.
    ///
    /// **Boundary, restated because it is the easy mistake (ADR-0047 §D4):** a
    /// `.canvas`-sourced task has no note underneath it and inherits nothing - a board
    /// has no frontmatter, so `notes[task.sourcePath]` is simply absent for one, and
    /// this falls through to nil exactly as it should without a special case.
    func effectiveCategory(of task: TaskItem) -> String? {
        if let project = task.project { return project.value }
        return notes[task.sourcePath]?.categorySlug
    }

    /// Every note carrying `pergamenum-category: <slug>`, first in vault order (path order,
    /// the tie-break `VaultSession.categoryViolations` reports as `duplicateHome`). More
    /// than one is the rare, lint-reported state; `setCategoryHome` is what clears it.
    func notesClaimingCategory(_ slug: String) -> [NoteRecord] {
        notes.values
            .filter { $0.categorySlug == slug }
            .sorted { $0.relativePath < $1.relativePath }
    }

    /// The category's "home" (SPEC "Note ↔ category"): the first claimant, or nil when no
    /// note carries the slug. One resolver for the category view and for the write that
    /// displaces a previous home, so the two cannot disagree about which note is "the" one.
    func homeNote(ofCategory slug: String) -> NoteRecord? {
        notesClaimingCategory(slug).first
    }

    /// `#project-*` values effective on at least one task and absent from the registry
    /// (SPEC "Implicit category"). Derived here, never persisted.
    func implicitCategories(registry: CategoryRegistry) -> Set<String> {
        let registered = Set(registry.entries.map(\.slug))
        var implicit: Set<String> = []
        for task in allTasks {
            guard let slug = effectiveCategory(of: task), !registered.contains(slug) else { continue }
            implicit.insert(slug)
        }
        return implicit
    }

    /// A category's task set (SPEC "Rollup"). `rolledUp` true is the category's own
    /// effective tasks plus each child's; false is direct tasks only - the category
    /// view's header section, before "one group per child" (SPEC "UI flows").
    func tasks(inCategory slug: String, registry: CategoryRegistry, rolledUp: Bool) -> [TaskItem] {
        let slugs = rolledUp ? registry.subtreeSlugs(of: slug) : [slug]
        return allTasks.filter { task in
            guard let category = effectiveCategory(of: task) else { return false }
            return slugs.contains(category)
        }
    }

    /// Rollup progress over a category's subtree: `done ÷ (open + done)`, `[x]` done,
    /// `[ ]`/`[>]` open, `[-]` excluded from both sides (SPEC "Rollup" - not
    /// `TaskItem.State.isOpen` applied naively: `.rescheduled` counts as open and
    /// `.cancelled` counts on neither side, so the denominator is not the task count).
    func progress(ofCategory slug: String, registry: CategoryRegistry) -> TaskProgress {
        let subtreeTasks = tasks(inCategory: slug, registry: registry, rolledUp: true)
        let done = subtreeTasks.filter { $0.state == .done }.count
        let open = subtreeTasks.filter { $0.state == .open || $0.state == .rescheduled }.count
        return TaskProgress(done: done, total: done + open)
    }
}
