import Foundation

/// A category row being dragged onto another one (R-01's drag gap): the dragged slug and
/// nothing else - `TaskDragPayload`'s own reasoning (`Sources/Features/Today/TaskDrag.swift`),
/// restated for a drag that never leaves this window and therefore needs no declared uniform
/// type. Deliberately its own type rather than a reuse of `TaskDragPayload`, which names a
/// task's file and line - a category row has neither.
struct CategoryDragPayload: Equatable {
    let slug: String

    var text: String { slug }

    init(slug: String) {
        self.slug = slug
    }

    /// `nil` for an empty string only: unlike `TaskDragPayload`'s two-part grammar, any
    /// non-empty slug is structurally acceptable here - `CategoryDropResolver` is what
    /// decides whether a *particular* slug names anything, against the registry, not this
    /// initializer.
    init?(text: String) {
        guard !text.isEmpty else { return nil }
        self.slug = text
    }
}

/// What dropping one category row onto another resolves to.
enum CategoryDropAction: Equatable {
    /// The dragged category becomes a child of `parent`, a top-level slug
    /// (`VaultSession.reparentCategory`).
    case reparent(dragged: String, parent: String)
    /// `slugs`, in this order, become the new sibling order under `parent` - `nil` for the
    /// top level (`VaultSession.reorderCategories`).
    case reorder(parent: String?, slugs: [String])
}

/// The pure mapping a category row's drop applies (R-01), with no SwiftUI import so it is
/// testable without a gesture (`Tests/CategoryDropTests.swift`) - PG-162's open macOS 27
/// UI-test drag regression is why the sidebar drag itself stays unit-tested only, the same
/// call Task 5 made for the task-onto-category drop.
///
/// Sibling-first, then reparent: two categories that already share a parent - including two
/// top-level ones, whose shared "parent" is `nil` - are read as a reorder even when the
/// target happens to be top-level, because sharing a parent is the more specific fact. A
/// reparent is only proposed once that reading is ruled out.
///
/// This function never validates beyond what it needs to choose a case - a stale slug, a
/// self-drop, or a relationship neither move describes all resolve to `nil` - and defers to
/// `CategoryRegistry.validating(_:)`, reached through `VaultSession.reparentCategory`/
/// `reorderCategories`, for everything else (ADR-0047 §D3). A caller ignores a refusal from
/// either exactly as the existing task-onto-category drop already does
/// (`VaultController+TaskDrop.swift`).
struct CategoryDropResolver {
    static func resolve(
        dragged draggedSlug: String, ontoTarget targetSlug: String, in registry: CategoryRegistry
    ) -> CategoryDropAction? {
        guard draggedSlug != targetSlug else { return nil }
        let bySlug = Dictionary(uniqueKeysWithValues: registry.entries.map { ($0.slug, $0) })
        guard let dragged = bySlug[draggedSlug], let target = bySlug[targetSlug] else { return nil }

        if dragged.parent == target.parent {
            var siblings = registry.entries
                .filter { $0.parent == target.parent }
                .sorted { $0.order < $1.order }
            guard let from = siblings.firstIndex(where: { $0.slug == draggedSlug }),
                  let to = siblings.firstIndex(where: { $0.slug == targetSlug })
            else { return nil }
            siblings.insert(siblings.remove(at: from), at: to)
            return .reorder(parent: target.parent, slugs: siblings.map(\.slug))
        }

        if target.parent == nil, dragged.parent != target.slug {
            return .reparent(dragged: draggedSlug, parent: target.slug)
        }

        return nil
    }
}
