import Foundation

/// The Attività pane's single derived selection (ADR-0047 §D6): one of the five views of
/// SPEC §7.4, or a category row.
///
/// Before this type, `TasksView` held one `@State var view: IndexSnapshot.TaskView` and
/// nothing named "a category is showing" - the same shape ADR-0024 already fixed for the
/// Workspace tree, where a folder row and a board row used to be two variables that had
/// to be kept in agreement by hand. One value here means the sidebar and the list can
/// never each believe a different thing is on screen.
enum TaskPaneSelection: Equatable, Sendable {
    case view(IndexSnapshot.TaskView)
    case category(String)

    /// The five-view case, or `nil` when a category is showing - `TaskViewSidebar`'s own
    /// highlight reads this rather than pattern-matching `self` at every row.
    var taskView: IndexSnapshot.TaskView? {
        if case .view(let view) = self { view } else { nil }
    }

    /// The category slug, or `nil` when one of the five views is showing.
    var categorySlug: String? {
        if case .category(let slug) = self { slug } else { nil }
    }
}
