import Foundation

extension Navigation {
    /// A request to open the Tags pane narrowed to one tag (n1-seams R-12): a request and not a
    /// call, for the reason `OutlineJump` is one. `id` makes two clicks on the same tag two
    /// events. One pending request at most: a second tag replaces the first, and the Tags pane
    /// consumes it with `takeTagFilter()`.
    struct TagFilterRequest: Equatable {
        let id: Int
        let tag: Tag
    }

    /// The Tags pane, narrowed to `tag` once it reads the request. Pane first, request second,
    /// the order `WindowPlace.apply` keeps for every anchor.
    func showTag(_ tag: Tag) {
        pane = .tags
        lastTagFilterID += 1
        tagFilter = TagFilterRequest(id: lastTagFilterID, tag: tag)
    }

    /// The pending tag, handed over once: the request is cleared as it is read, so nothing
    /// accumulates and the same pane appearing again narrows to nothing.
    func takeTagFilter() -> Tag? {
        defer { tagFilter = nil }
        return tagFilter?.tag
    }
}
